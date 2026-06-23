import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';

class OrderDetailCommonHelpers {
  static String tableDisplayName({
    required String tableNumber,
    required String floor,
  }) {
    final normalizedFloor = floor.toLowerCase();
    if (normalizedFloor == 'second') {
      return 'კუპე $tableNumber';
    }
    return 'მაგიდა $tableNumber';
  }

  /// Compact table label for headers, e.g. `T 7` or `T 6/7` for multi-table
  /// orders, instead of repeating "მაგიდა" for each number.
  static String compactTableLabel(Order order) {
    if (order.tableNumbers.isEmpty) {
      return '—';
    }
    return 'T ${order.tableNumbers.join('/')}';
  }

  static String orderTableDisplayLabel(Order order) {
    return order.tableNumbers
        .map(
          (table) => tableDisplayName(tableNumber: table, floor: order.floor),
        )
        .join(', ');
  }

  static String kitchenTableLabel(Order order) {
    final normalizedFloor = order.floor.toLowerCase();
    if (normalizedFloor == 'second') {
      return order.tableNumbers
          .map((table) => '$table, კუპე $table')
          .join(' / ');
    }
    return order.tableNumbers.join(', ');
  }

  static bool isFinalizedStatus(String status) {
    return status == 'paid' || status == 'cancelled' || status == 'closed';
  }

  static bool isTakeAway(Order order) {
    final floorLabel = order.floor.toLowerCase();
    if (floorLabel == 'takeaway') {
      return true;
    }
    return order.tableNumbers.any((table) {
      final normalized = table.toLowerCase();
      return normalized.startsWith('ta-') || normalized.contains('take away');
    });
  }

  static bool showReservationDetails(Reservation? reservation) {
    if (reservation == null) {
      return false;
    }
    final name = reservation.customerName.trim();
    final phone = reservation.customerPhone.trim();
    final hasName = name.isNotEmpty && name.toLowerCase() != 'walk-in';
    final hasPhone = phone.isNotEmpty && phone != '-' && phone != '--';
    return reservation.isTakeAway || hasName || hasPhone;
  }

  static String? reservationCustomerName(Reservation? reservation) {
    if (reservation == null) {
      return null;
    }
    final name = reservation.customerName.trim();
    if (name.isEmpty || name.toLowerCase() == 'walk-in') {
      return null;
    }
    return name;
  }

  static String? reservationCustomerPhone(Reservation? reservation) {
    if (reservation == null) {
      return null;
    }
    final phone = reservation.customerPhone.trim();
    if (phone.isEmpty || phone == '-' || phone == '--') {
      return null;
    }
    return phone;
  }

  static String? reservationScheduleDescription(Reservation? reservation) {
    if (reservation == null) {
      return null;
    }
    final time = reservation.reservationTime.trim();
    if (reservation.isTakeAway) {
      if (time.isEmpty) {
        return null;
      }
      return 'Pickup: $time';
    }
    final date = reservation.reservationDate;
    final formattedDate =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    if (time.isEmpty) {
      return 'Reservation: $formattedDate';
    }
    return 'Reservation: $formattedDate at $time';
  }

  static String? reservationGuestCountLabel(Reservation? reservation) {
    if (reservation == null || reservation.isTakeAway) {
      return null;
    }
    if (reservation.numberOfGuests <= 0) {
      return null;
    }
    return 'Guests: ${reservation.numberOfGuests}';
  }

  static String? reservationNotesLabel(Reservation? reservation) {
    if (reservation == null) {
      return null;
    }
    final notes = reservation.notes?.trim();
    if (notes == null || notes.isEmpty) {
      return null;
    }
    return notes;
  }

  /// Georgian label for an order-level status, used by the redesigned
  /// order detail header and per-row status badges.
  static String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'მოლოდინში';
      case 'confirmed':
        return 'დადასტურდა';
      case 'preparing':
        return 'მზადდება';
      case 'served':
        return 'მზად არის';
      case 'paid':
        return 'გადახდილია';
      case 'closed':
        return 'დახურულია';
      case 'cancelled':
        return 'გაუქმდა';
      default:
        return status;
    }
  }

  /// Human readable hall/zone label for an order's floor.
  static String zoneLabel(String floor) {
    switch (floor.toLowerCase()) {
      case 'second':
        return 'მეორე სართული';
      case 'takeaway':
        return 'გასატანი';
      case 'first':
      default:
        return 'მთავარი დარბაზი';
    }
  }

  /// Order number formatted like `YYMMDD-NNNN` (falls back to the raw id).
  static String formattedOrderNumber(Order order) {
    final created = order.createdAt;
    final yy = (created.year % 100).toString().padLeft(2, '0');
    final mm = created.month.toString().padLeft(2, '0');
    final dd = created.day.toString().padLeft(2, '0');
    final seq = order.orderId.toString().padLeft(4, '0');
    return '$yy$mm$dd-$seq';
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFACC15);
      case 'confirmed':
        return const Color(0xFF2563EB);
      case 'preparing':
        return const Color(0xFF7C3AED);
      case 'served':
        return const Color(0xFF16A34A);
      case 'paid':
      case 'closed':
        return const Color(0xFF64748B);
      case 'cancelled':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }
}
