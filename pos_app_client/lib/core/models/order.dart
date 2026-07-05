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
    final adjustedTotal =
        beforeDiscount - discountAmount + manualAdjustmentAmount;
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

  double _resolveEffectiveServiceFeeRate({double? serviceFeeRate}) {
    if (serviceFeeRate != null) {
      return serviceFeeRate >= 0 ? serviceFeeRate : 0;
    }

    final customPercent = customServiceFeePercentage;
    if (customPercent != null && customPercent > 0) {
      return customPercent / 100;
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
