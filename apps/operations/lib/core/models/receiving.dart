import 'package:vynic/core/models/inventory.dart';

/// Where a Receiving document is in its life.
///
/// The three values are not cosmetic. A draft has moved no stock, a posted
/// document is the only kind that has, and a cancelled one keeps both its
/// original movements and their reversals.
enum ReceivingStatus {
  draft('DRAFT'),
  posted('POSTED'),
  cancelled('CANCELLED');

  const ReceivingStatus(this.wireValue);

  final String wireValue;

  static ReceivingStatus parse(String? raw) {
    final value = raw?.trim().toUpperCase() ?? '';
    return ReceivingStatus.values.firstWhere(
      (status) => status.wireValue == value,
      orElse: () => ReceivingStatus.draft,
    );
  }
}

enum StockMovementType {
  receiving('RECEIVING'),
  receivingReversal('RECEIVING_REVERSAL'),
  unknown('UNKNOWN');

  const StockMovementType(this.wireValue);

  final String wireValue;

  /// A movement kind a later step introduces reads as [unknown] rather than
  /// failing to decode: this build shows it plainly instead of hiding it.
  static StockMovementType parse(String? raw) {
    final value = raw?.trim().toUpperCase() ?? '';
    return StockMovementType.values.firstWhere(
      (type) => type.wireValue == value,
      orElse: () => StockMovementType.unknown,
    );
  }
}

/// One line of a purchase document, frozen at the moment it was entered.
///
/// Money and quantities stay as the exact decimal text Cloud persisted. They
/// are parsed to `double` only where a widget needs to lay them out.
class ReceivingLine {
  const ReceivingLine({
    required this.id,
    required this.lineSequence,
    required this.stockItemId,
    required this.stockItemName,
    required this.enteredQuantity,
    required this.enteredUnit,
    required this.baseQuantity,
    required this.baseUnit,
    required this.unitPurchaseCost,
    required this.lineTotal,
    required this.effectiveBaseUnitCost,
    this.notes,
  });

  final String id;
  final int lineSequence;

  /// The durable identity. A later Stock Item rename never touches it.
  final String stockItemId;

  /// Historical display context, not identity.
  final String stockItemName;

  final String enteredQuantity;
  final InventoryUnit enteredUnit;
  final String baseQuantity;
  final InventoryUnit baseUnit;
  final String unitPurchaseCost;
  final String lineTotal;
  final String effectiveBaseUnitCost;
  final String? notes;

  double get enteredQuantityValue => double.tryParse(enteredQuantity) ?? 0;
  double get baseQuantityValue => double.tryParse(baseQuantity) ?? 0;
  double get lineTotalValue => double.tryParse(lineTotal) ?? 0;
  double get unitPurchaseCostValue => double.tryParse(unitPurchaseCost) ?? 0;

  /// True when the document says "10 box" but the ledger says "240 bottle".
  bool get isConverted => enteredUnit != baseUnit;

  factory ReceivingLine.fromJson(Map<String, dynamic> json) {
    return ReceivingLine(
      id: _text(json['id']) ?? '',
      lineSequence: (json['lineSequence'] as num?)?.toInt() ?? 0,
      stockItemId: _text(json['stockItemId']) ?? '',
      stockItemName: _text(json['stockItemName']) ?? '',
      enteredQuantity: _text(json['enteredQuantity']) ?? '0',
      enteredUnit: InventoryUnit.parse(_text(json['enteredUnit']) ?? 'piece'),
      baseQuantity: _text(json['baseQuantity']) ?? '0',
      baseUnit: InventoryUnit.parse(_text(json['baseUnit']) ?? 'piece'),
      unitPurchaseCost: _text(json['unitPurchaseCost']) ?? '0',
      lineTotal: _text(json['lineTotal']) ?? '0',
      effectiveBaseUnitCost: _text(json['effectiveBaseUnitCost']) ?? '0',
      notes: _text(json['notes']),
    );
  }
}

/// One entry in the authoritative quantity ledger.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.stockItemId,
    required this.movementType,
    required this.quantityDeltaBase,
    required this.baseUnit,
    required this.businessDate,
    required this.actorName,
    required this.createdAt,
    this.receivingId,
    this.reversalOfMovementId,
    this.receivingWaybillNumber,
    this.receivingSupplierName,
  });

  final String id;
  final String stockItemId;
  final StockMovementType movementType;
  final String quantityDeltaBase;
  final InventoryUnit baseUnit;
  final String businessDate;
  final String actorName;
  final DateTime createdAt;
  final String? receivingId;
  final String? reversalOfMovementId;
  final String? receivingWaybillNumber;
  final String? receivingSupplierName;

  double get quantityValue => double.tryParse(quantityDeltaBase) ?? 0;
  bool get isNegative => quantityValue < 0;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final receiving = json['receiving'];
    final nested = receiving is Map
        ? Map<String, dynamic>.from(receiving)
        : const <String, dynamic>{};
    return StockMovement(
      id: _text(json['id']) ?? '',
      stockItemId: _text(json['stockItemId']) ?? '',
      movementType: StockMovementType.parse(_text(json['movementType'])),
      quantityDeltaBase: _text(json['quantityDeltaBase']) ?? '0',
      baseUnit: InventoryUnit.parse(_text(json['baseUnit']) ?? 'piece'),
      businessDate: _text(json['businessDate']) ?? '',
      actorName: _text(json['actorName']) ?? '',
      createdAt: _date(json['createdAt']),
      receivingId: _text(json['receivingId']),
      reversalOfMovementId: _text(json['reversalOfMovementId']),
      receivingWaybillNumber: _text(nested['waybillNumber']),
      receivingSupplierName: _text(nested['supplierName']),
    );
  }
}

/// A procurement document: a waybill, its lines, and what it did to stock.
class Receiving {
  const Receiving({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.documentDate,
    required this.receivedAt,
    required this.status,
    required this.documentTotal,
    required this.lineCount,
    required this.createdByName,
    required this.createdAt,
    this.waybillNumber,
    this.invoiceNumber,
    this.notes,
    this.postedByName,
    this.postedAt,
    this.cancelledByName,
    this.cancelledAt,
    this.cancellationReason,
    this.lines = const <ReceivingLine>[],
    this.movements = const <StockMovement>[],
  });

  final String id;
  final String supplierId;

  /// Frozen at creation, so renaming or disabling a Supplier later never
  /// rewrites what this document said when the goods arrived.
  final String supplierName;

  final String documentDate;
  final DateTime receivedAt;
  final ReceivingStatus status;
  final String documentTotal;
  final int lineCount;
  final String createdByName;
  final DateTime createdAt;
  final String? waybillNumber;
  final String? invoiceNumber;
  final String? notes;
  final String? postedByName;
  final DateTime? postedAt;
  final String? cancelledByName;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final List<ReceivingLine> lines;
  final List<StockMovement> movements;

  double get documentTotalValue => double.tryParse(documentTotal) ?? 0;
  bool get isDraft => status == ReceivingStatus.draft;
  bool get isPosted => status == ReceivingStatus.posted;
  bool get isCancelled => status == ReceivingStatus.cancelled;

  /// What posting did to stock, before any reversal.
  List<StockMovement> get originalMovements => movements
      .where((movement) => movement.movementType == StockMovementType.receiving)
      .toList(growable: false);

  /// What cancelling put back. Never a deletion of the line above it.
  List<StockMovement> get reversalMovements => movements
      .where(
        (movement) =>
            movement.movementType == StockMovementType.receivingReversal,
      )
      .toList(growable: false);

  factory Receiving.fromJson(Map<String, dynamic> json) {
    return Receiving(
      id: _text(json['id']) ?? '',
      supplierId: _text(json['supplierId']) ?? '',
      supplierName: _text(json['supplierName']) ?? '',
      documentDate: _text(json['documentDate']) ?? '',
      receivedAt: _date(json['receivedAt']),
      status: ReceivingStatus.parse(_text(json['status'])),
      documentTotal: _text(json['documentTotal']) ?? '0.00',
      lineCount: (json['lineCount'] as num?)?.toInt() ?? 0,
      createdByName: _text(json['createdByName']) ?? '',
      createdAt: _date(json['createdAt']),
      waybillNumber: _text(json['waybillNumber']),
      invoiceNumber: _text(json['invoiceNumber']),
      notes: _text(json['notes']),
      postedByName: _text(json['postedByName']),
      postedAt: _optionalDate(json['postedAt']),
      cancelledByName: _text(json['cancelledByName']),
      cancelledAt: _optionalDate(json['cancelledAt']),
      cancellationReason: _text(json['cancellationReason']),
      lines: (json['lines'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => ReceivingLine.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
      movements: (json['movements'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => StockMovement.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }
}

/// One page of Receiving history.
class ReceivingPage {
  const ReceivingPage({required this.receivings, this.nextCursor});

  final List<Receiving> receivings;
  final String? nextCursor;

  factory ReceivingPage.fromJson(Map<String, dynamic> json) {
    return ReceivingPage(
      receivings: (json['receivings'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Receiving.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
      nextCursor: _text(json['nextCursor']),
    );
  }
}

/// A Stock Item with its derived balance and its recent ledger history.
class StockItemDetail {
  const StockItemDetail({
    required this.item,
    this.recentMovements = const <StockMovement>[],
  });

  final StockItem item;
  final List<StockMovement> recentMovements;

  factory StockItemDetail.fromJson(Map<String, dynamic> json) {
    return StockItemDetail(
      item: StockItem.fromJson(json),
      recentMovements: (json['recentMovements'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => StockMovement.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }
}

String? _text(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

DateTime _date(Object? raw) {
  return _optionalDate(raw) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

DateTime? _optionalDate(Object? raw) {
  return DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
}
