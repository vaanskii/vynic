import 'package:hive/hive.dart';
import 'order_status.dart';
part 'order.g.dart';

@HiveType(typeId: 3)
class OrderItem extends HiveObject {
  @HiveField(0)
  String itemKey; // e.g., "Beer - 0.5L" or "Khinkali"

  @HiveField(1)
  String itemName;

  @HiveField(2)
  double unitPrice;

  @HiveField(3)
  int quantity;

  @HiveField(4)
  double total;

  @HiveField(5)
  String? comment; // Special instructions (e.g., "No onions", "Extra spicy")

  OrderItem({
    required this.itemKey,
    required this.itemName,
    required this.unitPrice,
    required this.quantity,
    required this.total,
    this.comment,
  });

  OrderItem clone() {
    return OrderItem(
      itemKey: itemKey,
      itemName: itemName,
      unitPrice: unitPrice,
      quantity: quantity,
      total: total,
      comment: comment,
    );
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      itemKey: json['itemKey'] ?? json['name'] ?? '',
      itemName: json['itemName'] ?? json['name'] ?? '',
      unitPrice: (json['unitPrice'] ?? json['price'] ?? 0.0).toDouble(),
      quantity: json['quantity'] ?? 0,
      total: (json['total'] ?? (json['quantity'] ?? 0) * (json['price'] ?? 0.0))
          .toDouble(),
      comment: json['comment'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemKey': itemKey,
      'itemName': itemName,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'total': total,
      'comment': comment,
    };
  }
}

@HiveType(typeId: 4)
class Order extends HiveObject {
  @HiveField(0)
  int orderId;

  @HiveField(1)
  List<String> tableNumbers;

  @HiveField(2)
  String floor;

  @HiveField(3)
  List<OrderItem> items;

  @HiveField(4)
  double totalAmount;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  String createdBy; // Username of waiter/admin

  @HiveField(7)
  String status; // 'pending', 'confirmed', 'preparing', 'served', 'paid', 'cancelled'

  @HiveField(8)
  DateTime? updatedAt;

  @HiveField(9)
  bool includeServiceFee; // Whether to include configurable service fee

  @HiveField(10)
  String? paymentMethod; // 'card' or 'cash'

  @HiveField(11)
  DateTime? closedAt; // When the order was closed/paid

  @HiveField(12)
  double discountAmount; // Discount in GEL

  @HiveField(13)
  String? packageId; // Reference to package if this order uses a package

  @HiveField(14)
  String? packageName; // Cached package name

  @HiveField(15)
  double packagePrice; // Fixed package price (no service fee applied)

  @HiveField(16)
  List<OrderItem> packageItems; // Items from package (read-only for waiters)

  @HiveField(17)
  double packageUnitPrice; // Price per guest for the package

  @HiveField(18)
  int packageGuestCount; // Number of guests covered by the package

  static DateTime Function()? timestampResolver;
  @HiveField(19)
  double manualAdjustmentAmount; // Manual adjustments applied to the order total

  @HiveField(20)
  String? openedByUserId; // Username of who opened/activated the table (for ownership-based closing)

  @HiveField(21)
  double? customServiceFeePercentage; // Per-order override percentage

  /// Idempotency key linking this order to its sale record when it is closed.
  /// Schema-only for now (docs/VYNIC_ROADMAP.md Task 1): nothing writes it
  /// until the atomic close-table flow lands (Task 2). Always null for
  /// orders closed before that flow exists.
  @HiveField(22)
  String? closureId;

  /// Money the guest paid before this order was closed — a reservation
  /// deposit, typically.
  ///
  /// Held separately from [discountAmount] because the two are opposite
  /// things that happened to share a field: a discount reduces what the guest
  /// owes, an advance reduces only what is left to *collect*. Both subtract
  /// from [totalAmount], but only the discount reduces the value of the sale.
  /// Migration v6 moved every stored advance out of `discountAmount`.
  @HiveField(23)
  double advanceAmount;

  /// The business date (`YYYY-MM-DD`) the advance was taken on, which is not
  /// necessarily the date the order closes on.
  @HiveField(24)
  String? advanceCollectedOn;

  /// Links to the advance receipt in the sales box, so the receipt can be
  /// updated in place rather than duplicated when the amount is edited.
  @HiveField(25)
  String? advanceReceiptId;

  // Not persisted in Hive — populated from server for takeaway orders
  String customerName;
  String customerPhone;
  String pickupTime;

  static double Function()? serviceFeeRateResolver;

  Order({
    required this.orderId,
    required this.tableNumbers,
    required this.floor,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    required this.createdBy,
    this.status = 'pending',
    this.updatedAt,
    this.includeServiceFee = false,
    this.paymentMethod,
    this.closedAt,
    this.discountAmount = 0.0,
    this.packageId,
    this.packageName,
    this.packagePrice = 0.0,
    List<OrderItem>? packageItems,
    this.packageUnitPrice = 0.0,
    this.packageGuestCount = 0,
    this.manualAdjustmentAmount = 0.0,
    this.openedByUserId,
    this.customServiceFeePercentage,
    this.closureId,
    this.advanceAmount = 0.0,
    this.advanceCollectedOn,
    this.advanceReceiptId,
    this.customerPhone = '',
    this.pickupTime = '',
    this.customerName = '',
  }) : packageItems = packageItems ?? [];

  Order clone() {
    return Order(
      orderId: orderId,
      tableNumbers: List.from(tableNumbers),
      floor: floor,
      items: items.map((i) => i.clone()).toList(),
      totalAmount: totalAmount,
      createdAt: createdAt,
      createdBy: createdBy,
      status: status,
      updatedAt: updatedAt,
      includeServiceFee: includeServiceFee,
      paymentMethod: paymentMethod,
      closedAt: closedAt,
      discountAmount: discountAmount,
      packageId: packageId,
      packageName: packageName,
      packagePrice: packagePrice,
      packageItems: packageItems.map((i) => i.clone()).toList(),
      packageUnitPrice: packageUnitPrice,
      packageGuestCount: packageGuestCount,
      manualAdjustmentAmount: manualAdjustmentAmount,
      openedByUserId: openedByUserId,
      customServiceFeePercentage: customServiceFeePercentage,
      closureId: closureId,
      advanceAmount: advanceAmount,
      advanceCollectedOn: advanceCollectedOn,
      advanceReceiptId: advanceReceiptId,
      customerPhone: customerPhone,
      pickupTime: pickupTime,
      customerName: customerName,
    );
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final itemsList =
        (json['items'] as List<dynamic>?)
            ?.map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];

    return Order(
      orderId: json['posOrderId'] ?? json['orderId'] ?? 0,
      tableNumbers:
          (json['tableNumbers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      floor: json['floor'] ?? '',
      items: itemsList,
      totalAmount: (json['totalAmount'] ?? 0.0).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      createdBy: json['waiterName'] ?? json['createdBy'] ?? '',
      status: json['status'] ?? 'pending',
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
      includeServiceFee: json['includeServiceFee'] ?? false,
      paymentMethod: json['paymentMethod'],
      closedAt: json['closedAt'] != null
          ? DateTime.parse(json['closedAt'])
          : null,
      discountAmount: (json['discountAmount'] ?? 0.0).toDouble(),
      packageId: json['packageId'],
      packageName: json['packageName'],
      packagePrice: (json['packagePrice'] ?? 0.0).toDouble(),
      packageUnitPrice: (json['packageUnitPrice'] ?? 0.0).toDouble(),
      packageGuestCount: json['packageGuestCount'] ?? 0,
      manualAdjustmentAmount: (json['manualAdjustmentAmount'] ?? 0.0)
          .toDouble(),
      openedByUserId: json['openedByUserId'],
      customServiceFeePercentage:
          (json['customServiceFeePercentage'] as num?)?.toDouble() ??
          (json['serviceFeePercent'] as num?)?.toDouble(),
      closureId: json['closureId'] as String?,
      customerPhone: json['customerPhone'] as String? ?? '',
      pickupTime: json['pickupTime'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'posOrderId': orderId,
      'tableNumbers': tableNumbers,
      'floor': floor,
      'items': items.map((i) => i.toJson()).toList(),
      'totalAmount': totalAmount,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'waiterName': createdBy,
      'status': status,
      'updatedAt': updatedAt?.toIso8601String(),
      'includeServiceFee': includeServiceFee,
      'paymentMethod': paymentMethod,
      'closedAt': closedAt?.toIso8601String(),
      'discountAmount': discountAmount,
      'packageId': packageId,
      'packageName': packageName,
      'packagePrice': packagePrice,
      'packageUnitPrice': packageUnitPrice,
      'packageGuestCount': packageGuestCount,
      'manualAdjustmentAmount': manualAdjustmentAmount,
      'openedByUserId': openedByUserId,
      'customServiceFeePercentage': customServiceFeePercentage,
      'closureId': closureId,
      'advanceAmount': advanceAmount,
      'advanceCollectedOn': advanceCollectedOn,
      'advanceReceiptId': advanceReceiptId,
    };
  }

  // Calculate total from items
  // Note: Service fee only applies to additional items, NOT package price
  void recalculateTotal({double? serviceFeeRate}) {
    final packageTotal = _resolvePackageTotal();
    final additionalItemsTotal = items.fold(
      0.0,
      (sum, item) => sum + item.total,
    );
    final rate = _resolveEffectiveServiceFeeRate(
      serviceFeeRate: serviceFeeRate,
    );

    // Service fee only on additional items, not package
    final serviceFee = includeServiceFee ? additionalItemsTotal * rate : 0.0;

    final beforeDiscount = packageTotal + additionalItemsTotal + serviceFee;
    // The advance comes off the same way a discount does — it is money the
    // guest no longer has to hand over — but it is subtracted from a separate
    // field so the closure can put it back to reach the gross sale value.
    final adjustedTotal =
        beforeDiscount -
        discountAmount -
        effectiveAdvanceAmount +
        manualAdjustmentAmount;
    totalAmount = double.parse(adjustedTotal.toStringAsFixed(2));
    if (totalAmount < 0) totalAmount = 0;
    packagePrice = double.parse(packageTotal.toStringAsFixed(2));
  }

  // Get items subtotal (without service fee)
  // This returns ONLY additional items, not package items
  double getItemsSubtotal() {
    return items.fold(0.0, (sum, item) => sum + item.total);
  }

  // Get package subtotal
  double getPackageSubtotal() {
    return _resolvePackageTotal();
  }

  // Get additional items subtotal (same as getItemsSubtotal)
  double getAdditionalItemsSubtotal() {
    return getItemsSubtotal();
  }

  // Get service fee amount
  // Service fee only applies to additional items, NOT package price
  double getServiceFee({double? serviceFeeRate}) {
    final rate = _resolveEffectiveServiceFeeRate(
      serviceFeeRate: serviceFeeRate,
    );
    if (!includeServiceFee || rate <= 0) {
      return 0.0;
    }
    // Only calculate service fee on additional items
    return double.parse(
      (getAdditionalItemsSubtotal() * rate).toStringAsFixed(2),
    );
  }

  double _resolvePackageTotal() {
    if (packageUnitPrice > 0 && packageGuestCount > 0) {
      return packageUnitPrice * packageGuestCount;
    }
    return packagePrice;
  }

  /// The advance on this order.
  ///
  /// Before v6 an advance was stored in `discountAmount` — the POS's advance
  /// dialog was the only writer of that field, so every stored value was one.
  /// The v6 migration moved them all across before any order is read, which
  /// is why this does not fall back: a `discountAmount` surviving that
  /// migration is a genuine discount and must not be added back to gross.
  double get effectiveAdvanceAmount => advanceAmount;

  /// What the guest consumed: the balance still due plus the advance already
  /// taken. This is the value of the sale, and it does not move when a
  /// deposit is collected earlier.
  double get grossAmount =>
      double.parse((totalAmount + effectiveAdvanceAmount).toStringAsFixed(2));

  // Toggle service fee
  void toggleServiceFee({double? serviceFeeRate}) {
    includeServiceFee = !includeServiceFee;
    recalculateTotal(serviceFeeRate: serviceFeeRate);
    updatedAt = _resolveTimestamp();
    save();
  }

  // Set discount amount
  void setDiscount(double amount, {double? serviceFeeRate}) {
    discountAmount = amount;
    recalculateTotal(serviceFeeRate: serviceFeeRate);
    updatedAt = _resolveTimestamp();
    save();
  }

  /// Sets the advance already collected against this order.
  ///
  /// [collectedOn] is the business date the money was taken, which the
  /// closure needs because it is often not the date the order closes on.
  void setAdvance(
    double amount, {
    required String collectedOn,
    String? receiptId,
    double? serviceFeeRate,
  }) {
    advanceAmount = double.parse(amount.toStringAsFixed(2));
    if (advanceAmount <= 0) {
      advanceAmount = 0.0;
      advanceCollectedOn = null;
      advanceReceiptId = null;
    } else {
      advanceCollectedOn = collectedOn;
      advanceReceiptId = receiptId ?? advanceReceiptId;
    }
    recalculateTotal(serviceFeeRate: serviceFeeRate);
    updatedAt = _resolveTimestamp();
    save();
  }

  void setManualAdjustment(double amount, {double? serviceFeeRate}) {
    manualAdjustmentAmount = double.parse(amount.toStringAsFixed(2));
    recalculateTotal(serviceFeeRate: serviceFeeRate);
    updatedAt = _resolveTimestamp();
    save();
  }

  // Update order status
  void updateStatus(String newStatus) {
    status = newStatus;
    updatedAt = _resolveTimestamp();
    save();
  }

  /// Typed view of [status]. Storage stays the raw `String` field (Hive
  /// field 7, unchanged) — this is a computed read/write wrapper, not a new
  /// source of truth. See `core/models/order_status.dart`.
  OrderStatus get statusEnum => OrderStatus.fromStorage(status);
  set statusEnum(OrderStatus value) => status = value.storageValue;

  // Add item to order
  void addItem(OrderItem item) {
    // Check if item already exists
    final existingIndex = items.indexWhere((i) => i.itemKey == item.itemKey);
    if (existingIndex != -1) {
      items[existingIndex].quantity += item.quantity;
      items[existingIndex].total =
          items[existingIndex].unitPrice * items[existingIndex].quantity;
    } else {
      items.add(item);
    }
    recalculateTotal();
    updatedAt = _resolveTimestamp();
    save();
  }

  // Remove item from order
  void removeItem(String itemKey) {
    items.removeWhere((item) => item.itemKey == itemKey);
    recalculateTotal();
    updatedAt = _resolveTimestamp();
    save();
  }

  // Update item quantity
  void updateItemQuantity(String itemKey, int newQuantity) {
    final index = items.indexWhere((i) => i.itemKey == itemKey);
    if (index != -1) {
      if (newQuantity <= 0) {
        removeItem(itemKey);
      } else {
        items[index].quantity = newQuantity;
        items[index].total = items[index].unitPrice * newQuantity;
        recalculateTotal();
        updatedAt = _resolveTimestamp();
        save();
      }
    }
  }

  double getEffectiveServiceFeePercentage({double? globalDefaultPercentage}) {
    final custom = customServiceFeePercentage;
    if (custom != null && custom >= 0) {
      return custom;
    }
    if (globalDefaultPercentage != null && globalDefaultPercentage >= 0) {
      return globalDefaultPercentage;
    }
    return _resolveDefaultServiceFeeRate() * 100;
  }

  /// Single source of truth for the rate used by both [recalculateTotal] and
  /// [getServiceFee]. Resolution order:
  ///
  /// 1. this order's own [customServiceFeePercentage],
  /// 2. an explicitly supplied [serviceFeeRate],
  /// 3. the global default from [serviceFeeRateResolver].
  ///
  /// The per-order override must win over an explicitly passed rate. The close
  /// flow recalculates the total with the *global* rate while the sale record
  /// reads [getServiceFee] (which has no rate to pass); when an explicit rate
  /// took precedence those two disagreed, so the guest was charged one amount
  /// and a different one was booked. Keeping the override first makes every
  /// caller — with or without an explicit rate — agree on one number.
  ///
  /// Note: a custom percentage of exactly 0 still falls through to the next
  /// tier (unchanged from before); "0% means no fee" is expressed by
  /// [includeServiceFee], which short-circuits both callers.
  double _resolveEffectiveServiceFeeRate({double? serviceFeeRate}) {
    final customPercent = customServiceFeePercentage;
    if (customPercent != null && customPercent > 0) {
      return customPercent / 100;
    }

    if (serviceFeeRate != null) {
      return serviceFeeRate >= 0 ? serviceFeeRate : 0;
    }

    return _resolveDefaultServiceFeeRate();
  }

  double _resolveDefaultServiceFeeRate() {
    try {
      final resolver = serviceFeeRateResolver;
      if (resolver != null) {
        final rate = resolver();
        if (rate >= 0) {
          return rate;
        }
      }
    } catch (_) {}
    return 0.10;
  }

  static DateTime _resolveTimestamp() {
    try {
      final resolver = timestampResolver;
      if (resolver != null) {
        return resolver();
      }
    } catch (_) {}
    return DateTime.now();
  }
}
