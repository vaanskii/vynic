import 'package:hive/hive.dart';

part 'table.g.dart';

@HiveType(typeId: 2)
class TableModel extends HiveObject {
  @HiveField(0)
  String tableNumber;

  @HiveField(1)
  String floor; // 'first' or 'second'

  @HiveField(2)
  bool isReserved;

  @HiveField(3)
  DateTime? reservedAt;

  @HiveField(4)
  String? reservedBy; // Username of the waiter/admin who reserved it

  @HiveField(5)
  int? activeOrderId; // Reference to the active order

  @HiveField(6)
  String? reservationId; // Reference to the reservation (if table is reserved for a reservation)

  double? currentBill; // Only used for mobile monitoring API

  TableModel({
    required this.tableNumber,
    required this.floor,
    this.isReserved = false,
    this.reservedAt,
    this.reservedBy,
    this.activeOrderId,
    this.reservationId,
  });

  // Helper method to get display name
  String get displayName => 'Table $tableNumber';

  // Helper method to reserve table for an order
  void reserve(String username, int orderId, {String? reservationId}) {
    isReserved = true;
    reservedAt = DateTime.now();
    reservedBy = username;
    activeOrderId = orderId;
    this.reservationId = reservationId;
  }

  // Helper method to reserve table for a reservation (without order)
  void reserveForReservation(String username, String resId) {
    isReserved = true;
    reservedAt = DateTime.now();
    reservedBy = username;
    activeOrderId = null; // No order yet
    reservationId = resId; // Link to reservation
  }

  // Helper method to free table
  void free() {
    isReserved = false;
    reservedAt = null;
    reservedBy = null;
    activeOrderId = null;
    reservationId = null;
  }

  factory TableModel.fromJson(Map<String, dynamic> json) {
    final activeOrderId = json['activeOrderId'];
    final isReserved =
        json['isReserved'] == true ||
        json['isOccupied'] == true ||
        activeOrderId != null;
    return TableModel(
      tableNumber: json['tableNumber'] ?? '',
      floor: json['floor'] ?? '',
      isReserved: isReserved,
      reservedAt: json['reservedAt'] != null
          ? DateTime.parse(json['reservedAt'])
          : null,
      reservedBy: json['reservedBy'],
      activeOrderId: isReserved ? activeOrderId : null,
      reservationId: json['reservationId'],
    )..currentBill = isReserved ? (json['currentBill'] ?? 0).toDouble() : 0.0;
  }

  Map<String, dynamic> toJson() {
    return {
      'tableNumber': tableNumber,
      'floor': floor,
      'isReserved': isReserved,
      'reservedAt': reservedAt?.toIso8601String(),
      'reservedBy': reservedBy,
      'activeOrderId': activeOrderId,
      'reservationId': reservationId,
      'currentBill': currentBill,
    };
  }
}
