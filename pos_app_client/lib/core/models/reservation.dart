import 'package:hive/hive.dart';
import 'order.dart';

part 'reservation.g.dart';

@HiveType(typeId: 9)
class Reservation extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String customerName;

  @HiveField(2)
  String customerPhone;

  @HiveField(3)
  List<int> tableNumbers;

  @HiveField(4)
  DateTime reservationDate;

  @HiveField(5)
  String reservationTime; // HH:mm format

  @HiveField(6)
  int numberOfGuests;

  @HiveField(7)
  String? notes;

  @HiveField(8)
  DateTime createdAt;

  @HiveField(9)
  String createdBy; // Username who created the reservation

  @HiveField(10)
  String status; // 'pending', 'confirmed', 'cancelled', 'completed'

  @HiveField(11)
  List<OrderItem>? preOrderItems; // Menu items pre-selected for this reservation

  @HiveField(12)
  bool isTakeAway;

  @HiveField(13)
  int? linkedOrderId;

  Reservation({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.tableNumbers,
    required this.reservationDate,
    required this.reservationTime,
    required this.numberOfGuests,
    this.notes,
    required this.createdAt,
    required this.createdBy,
    this.status = 'pending',
    this.preOrderItems,
    this.isTakeAway = false,
    this.linkedOrderId,
  });
}
