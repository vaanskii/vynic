import 'package:hive/hive.dart';

part 'sale_record.g.dart';

/// One line item of a closed sale, mirroring the legacy map shape
/// `{itemName, quantity, unitPrice, total}` written by
/// `SalesRepository.saveSaleRecord`.
@HiveType(typeId: 16)
class SaleRecordItem extends HiveObject {
  @HiveField(0)
  String itemName;

  @HiveField(1)
  int quantity;

  @HiveField(2)
  double unitPrice;

  @HiveField(3)
  double total;

  @HiveField(4)
  String? comment;

  SaleRecordItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.comment,
  });

  /// Tolerant of both the sale-record shape (`itemName`/`unitPrice`) and the
  /// sync/report shape (`name`/`price`), like existing readers.
  factory SaleRecordItem.fromMap(Map<String, dynamic> map) {
    final quantity = (map['quantity'] as num?)?.toInt() ?? 0;
    final total = (map['total'] as num?)?.toDouble();
    final unitPrice =
        (map['unitPrice'] as num?)?.toDouble() ??
        (map['price'] as num?)?.toDouble() ??
        (quantity > 0 && total != null ? total / quantity : 0.0);
    return SaleRecordItem(
      itemName: (map['itemName'] ?? map['name'] ?? '').toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      total: total ?? unitPrice * quantity,
      comment: map['comment']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemName': itemName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'total': total,
      if (comment != null) 'comment': comment,
    };
  }
}

/// Typed sale record — the schema counterpart of the legacy `Map` records in
/// the Hive `sales` box (see `SalesRepository.saveSaleRecord`).
///
/// Task 1 scope (docs/VYNIC_ROADMAP.md): schema only. Nothing writes
/// [SaleRecord] instances yet; the payment path keeps writing legacy maps.
/// [toMap]/[fromMap] guarantee a lossless round trip with that legacy shape
/// so later tasks can dual-write and union-read without behavior change.
///
/// [closureId] is the future idempotency key for atomic table closure
/// (docs/VYNIC_ARCHITECTURE_PLAN.md §1). It is nullable because every
/// record written before that flow exists has no closure id.
@HiveType(typeId: 15)
class SaleRecord extends HiveObject {
  @HiveField(0)
  String? closureId;

  @HiveField(1)
  int orderId;

  @HiveField(2)
  List<String> tableNumbers;

  @HiveField(3)
  String floor;

  @HiveField(4)
  List<SaleRecordItem> items;

  @HiveField(5)
  double totalAmount;

  @HiveField(6)
  String paymentMethod;

  @HiveField(7)
  Map<String, double>? paymentBreakdown;

  @HiveField(8)
  String? customPaymentLabel;

  @HiveField(9)
  String createdBy;

  @HiveField(10)
  DateTime createdAt;

  @HiveField(11)
  DateTime closedAt;

  @HiveField(12)
  bool includeServiceFee;

  @HiveField(13)
  double discountAmount;

  @HiveField(14)
  double advanceAmount;

  @HiveField(15)
  double subtotalAmount;

  @HiveField(16)
  double manualAdjustmentAmount;

  @HiveField(17)
  Map<String, dynamic>? finalTransaction;

  /// Business date key (`YYYY-MM-DD`) — stored as `date` in the legacy maps.
  @HiveField(18)
  String businessDate;

  @HiveField(19)
  bool isCancelled;

  @HiveField(20)
  DateTime? cancelledAt;

  @HiveField(21)
  bool isFiscal;

  @HiveField(22)
  bool restoredToOrder;

  @HiveField(23)
  DateTime? restoredAt;

  @HiveField(24)
  String? restoredBy;

  /// Reserved for the tips workflow (roadmap P1-7). Always 0.0 until then.
  @HiveField(25)
  double tipAmount;

  /// Who performed the closure — reserved for atomic close (Task 2).
  @HiveField(26)
  String? closedById;

  SaleRecord({
    this.closureId,
    required this.orderId,
    required this.tableNumbers,
    required this.floor,
    required this.items,
    required this.totalAmount,
    required this.paymentMethod,
    this.paymentBreakdown,
    this.customPaymentLabel,
    required this.createdBy,
    required this.createdAt,
    required this.closedAt,
    required this.includeServiceFee,
    this.discountAmount = 0.0,
    this.advanceAmount = 0.0,
    required this.subtotalAmount,
    this.manualAdjustmentAmount = 0.0,
    this.finalTransaction,
    required this.businessDate,
    this.isCancelled = false,
    this.cancelledAt,
    this.isFiscal = true,
    this.restoredToOrder = false,
    this.restoredAt,
    this.restoredBy,
    this.tipAmount = 0.0,
    this.closedById,
  });

  static DateTime? _tryParseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Parses a legacy sales-box map. Mirrors the tolerance of
  /// `SalesRepository._mapSalesRecords` and the report readers:
  /// `totalAmount` falls back to `total`, booleans default like the read
  /// path (`isCancelled`/`restoredToOrder` false, `isFiscal` true).
  factory SaleRecord.fromMap(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    final breakdownRaw = map['paymentBreakdown'];
    final finalTransactionRaw = map['finalTransaction'];
    return SaleRecord(
      closureId: map['closureId']?.toString(),
      orderId: (map['orderId'] as num?)?.toInt() ?? 0,
      tableNumbers: ((map['tableNumbers'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      floor: (map['floor'] as String?) ?? 'first',
      items: rawItems
          .whereType<Map>()
          .map((it) => SaleRecordItem.fromMap(Map<String, dynamic>.from(it)))
          .toList(),
      totalAmount:
          (map['totalAmount'] as num?)?.toDouble() ??
          (map['total'] as num?)?.toDouble() ??
          0.0,
      paymentMethod: (map['paymentMethod'] as String?) ?? '',
      paymentBreakdown: breakdownRaw is Map
          ? breakdownRaw.map(
              (key, value) =>
                  MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0.0),
            )
          : null,
      customPaymentLabel: map['customPaymentLabel']?.toString(),
      createdBy: (map['createdBy'] as String?) ?? '',
      createdAt: _tryParseDate(map['createdAt']) ?? DateTime(1970),
      closedAt: _tryParseDate(map['closedAt']) ?? DateTime(1970),
      includeServiceFee: map['includeServiceFee'] == true,
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0.0,
      advanceAmount: (map['advanceAmount'] as num?)?.toDouble() ?? 0.0,
      subtotalAmount:
          (map['subtotalAmount'] as num?)?.toDouble() ??
          (map['totalAmount'] as num?)?.toDouble() ??
          (map['total'] as num?)?.toDouble() ??
          0.0,
      manualAdjustmentAmount:
          (map['manualAdjustmentAmount'] as num?)?.toDouble() ?? 0.0,
      finalTransaction: finalTransactionRaw is Map
          ? Map<String, dynamic>.from(finalTransactionRaw)
          : null,
      businessDate: (map['date'] as String?) ?? '',
      isCancelled: map['isCancelled'] == true,
      cancelledAt: _tryParseDate(map['cancelledAt']),
      isFiscal: map['isFiscal'] != false,
      restoredToOrder: map['restoredToOrder'] == true,
      restoredAt: _tryParseDate(map['restoredAt']),
      restoredBy: map['restoredBy']?.toString(),
      tipAmount: (map['tipAmount'] as num?)?.toDouble() ?? 0.0,
      closedById: map['closedById']?.toString(),
    );
  }

  /// Emits the exact legacy map shape written by
  /// `SalesRepository.saveSaleRecord` (after the v4 migration materialized
  /// the `isCancelled`/`restoredToOrder`/`isFiscal` defaults). Keys that the
  /// legacy writer only adds conditionally (`cancelledAt`, `restoredAt`,
  /// `restoredBy`) — and the new schema-only fields (`closureId`,
  /// `tipAmount`, `closedById`) — are likewise emitted only when set, so a
  /// legacy record round-trips byte-for-byte.
  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'tableNumbers': tableNumbers,
      'floor': floor,
      'items': items.map((item) => item.toMap()).toList(),
      'totalAmount': totalAmount,
      'total': totalAmount,
      'paymentMethod': paymentMethod,
      'paymentBreakdown': paymentBreakdown,
      'customPaymentLabel': customPaymentLabel,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'closedAt': closedAt.toIso8601String(),
      'includeServiceFee': includeServiceFee,
      'discountAmount': discountAmount,
      'advanceAmount': advanceAmount,
      'subtotalAmount': subtotalAmount,
      'manualAdjustmentAmount': manualAdjustmentAmount,
      'finalTransaction': finalTransaction,
      'date': businessDate,
      'isCancelled': isCancelled,
      if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
      'isFiscal': isFiscal,
      'restoredToOrder': restoredToOrder,
      if (restoredAt != null) 'restoredAt': restoredAt!.toIso8601String(),
      if (restoredBy != null) 'restoredBy': restoredBy,
      if (closureId != null) 'closureId': closureId,
      if (tipAmount != 0.0) 'tipAmount': tipAmount,
      if (closedById != null) 'closedById': closedById,
    };
  }
}
