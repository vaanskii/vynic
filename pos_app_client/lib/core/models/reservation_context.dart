class ReservationContext {
  final String customerName;
  final String customerPhone;
  final DateTime reservationDate;
  final String reservationTime;
  final List<String> tableLabels;
  final int numberOfGuests;
  final String? notes;

  const ReservationContext({
    required this.customerName,
    required this.customerPhone,
    required this.reservationDate,
    required this.reservationTime,
    required this.tableLabels,
    required this.numberOfGuests,
    this.notes,
  });
}
