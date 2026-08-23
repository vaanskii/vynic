import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/table_naming.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_names.dart';

class OrderDetailCommonHelpers {
  static String tableDisplayName({
    required String tableNumber,
    required String floor,
  }) {
    return TableNaming.table(tableNumber: tableNumber, floor: floor);
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
    return TableNaming.orderTables(order);
  }

  /// What the kitchen check says the food is for.
  ///
  /// This used to print „5, კუპე 5" for anything on the second floor — the
  /// number twice, once bare and once behind a word the floor editor does not
  /// use. The kitchen now reads the same name as the floor screen, so a runner
  /// carrying a plate is looking for a table that exists under that name.
  static String kitchenTableLabel(Order order) {
    return TableNaming.orderTables(order);
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

  // ------------------------------------------------------- layout-derived

  /// The table's own name, as set in the floor editor — „Table 1",
  /// „ფანჯარასთან". Multi-table orders join them.
  ///
  /// This is what the order screen puts in its title, so it has to agree with
  /// the floor plan the waiter just tapped. Falls back to the bare number for
  /// a table that no longer exists in the layout.
  static String tableTitle(Order order, {RestaurantTableLayout? layout}) {
    if (order.tableNumbers.isEmpty) {
      return '—';
    }
    final resolved = layout ?? DatabaseService.getRestaurantTableLayout();
    return order.tableNumbers
        .map(
          (number) => floorPlanTableNameOrNumber(
            resolved,
            floor: order.floor,
            tableNumber: number,
          ),
        )
        .join(' + ');
  }

  /// The zone's own name („სართული 1"), not a hardcoded hall name.
  ///
  /// [zoneLabel] is kept for the places that only have a floor string; this
  /// one prefers whatever the admin called the zone.
  static String zoneName(Order order, {RestaurantTableLayout? layout}) {
    final resolved = layout ?? DatabaseService.getRestaurantTableLayout();
    return resolved.zoneForLegacyFloor(order.floor)?.name ??
        zoneLabel(order.floor);
  }

  /// Seats across the order's tables, or null when none of them are in the
  /// layout (so the caller can drop the „N ადგილი" bit rather than show 0).
  static int? seatCount(Order order, {RestaurantTableLayout? layout}) {
    final resolved = layout ?? DatabaseService.getRestaurantTableLayout();
    var seats = 0;
    var found = false;
    for (final number in order.tableNumbers) {
      final definition = resolved.tableForLegacy(
        floor: order.floor,
        tableNumber: number,
      );
      if (definition == null) continue;
      found = true;
      seats += definition.capacity;
    }
    return found && seats > 0 ? seats : null;
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
