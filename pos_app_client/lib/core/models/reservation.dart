import 'package:hive/hive.dart';
import 'order.dart';
import 'reservation_status.dart';

part 'reservation.g.dart';

@HiveType(typeId: 9)
class Reservation extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String customerName;

  @HiveField(2)
  String customerPhone;

  /// Legacy encoded table codes (see
  /// `ReservationTableAvailability.encodeTableCode`). Still written for
  /// backups and the server wire format, but [tableRefs] is canonical —
  /// read tables via `ReservationTableAvailability.tableRefsOf`.
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

  /// Canonical table references as `floor/tableNumber` strings (see
  /// `TableRef`). Nullable so records written before db v3 still
  /// deserialize; the v2→v3 migration backfills it from [tableNumbers].
  @HiveField(14)
  List<String>? tableRefs;

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
    this.tableRefs,
  });

  /// Typed view of [status]. Storage stays the raw `String` field (Hive
  /// field 10, unchanged) — this is a computed read/write wrapper, not a new
  /// source of truth. See `core/models/reservation_status.dart` for the
  /// exact-match parsing and the note on `startsWith`-tolerant call sites
  /// this does not replace.
  ReservationStatus get statusEnum => ReservationStatus.fromStorage(status);
  set statusEnum(ReservationStatus value) => status = value.storageValue;
}
