import 'package:flutter/material.dart';

import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/services/database_service.dart';

class HomeReservationsHelper {
  const HomeReservationsHelper._();

  static String normalizeStatus(String status) {
    return status
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  static bool hasBeenSeated(String status) {
    final normalized = normalizeStatus(status);
    return normalized == 'in-progress' ||
        normalized == 'inprogress' ||
        normalized.startsWith('completed');
  }

  static DateTime normalizeDateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static List<Reservation> getAdminPanelReservations() {
    final currentDate = DatabaseService.getCurrentDate();
    final currentDateString = currentDate.toIso8601String().split('T')[0];
    final allReservations = DatabaseService.getAllReservations();

    final filtered = <Reservation>[];
    for (final reservation in allReservations) {
      if (reservation.notes != null &&
          reservation.notes!.startsWith('Order #')) {
        continue;
      }
      if (reservation.isTakeAway) {
        continue;
      }

      final reservationDateString = reservation.reservationDate
          .toIso8601String()
          .split('T')[0];
      if (reservationDateString.compareTo(currentDateString) < 0) {
        continue;
      }

      final normalizedStatus = normalizeStatus(reservation.status);
      final isConfirmed = normalizedStatus.startsWith('confirmed');
      final isCancelled =
          normalizedStatus.startsWith('cancelled') ||
          normalizedStatus.startsWith('canceled');

      if (isConfirmed || isCancelled) {
        filtered.add(reservation);
      }
    }

    // Newest first: most recently created reservation appears at the top.
    filtered.sort((a, b) {
      final createdComparison = b.createdAt.compareTo(a.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }
      final dateComparison = b.reservationDate.compareTo(a.reservationDate);
      if (dateComparison != 0) {
        return dateComparison;
      }
      return b.reservationTime.compareTo(a.reservationTime);
    });

    return filtered;
  }

  static int extractGuestCount(Map<String, dynamic> data) {
    final raw = data['numberOfGuests'] ?? data['guests'];
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw) ?? 0;
    }
    return 0;
  }

  static bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static List<String> buildKitchenCheckLines(Reservation reservation) {
    final lines = <String>[];
    final items = reservation.preOrderItems ?? const [];

    for (final item in items) {
      var itemStr = '${item.quantity}x ${item.itemName}';
      if (item.comment != null && item.comment!.trim().isNotEmpty) {
        itemStr += '\n  ⮑ ${item.comment!.trim()}';
      }
      lines.add(itemStr);
    }

    return lines;
  }

  static DateTime? buildKitchenTime(Reservation reservation) {
    final timeValue = reservation.reservationTime.trim();
    if (timeValue.isEmpty) {
      return reservation.reservationDate;
    }

    final parts = timeValue.split(':');
    if (parts.length < 2) {
      return reservation.reservationDate;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return reservation.reservationDate;
    }

    return DateTime(
      reservation.reservationDate.year,
      reservation.reservationDate.month,
      reservation.reservationDate.day,
      hour,
      minute,
    );
  }

  static String buildKitchenOrderLabel(Reservation reservation) {
    final name = reservation.customerName.trim();
    final time = reservation.reservationTime.trim();

    if (name.isNotEmpty && time.isNotEmpty) {
      return 'რეზერვაცია: $name • $time';
    }
    if (name.isNotEmpty) {
      return 'რეზერვაცია: $name';
    }
    if (time.isNotEmpty) {
      return 'რეზერვაცია: $time';
    }
    return 'რეზერვაცია';
  }

  static TimeOfDay? parseReservationTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parts = trimmed.split(':');
    if (parts.length < 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }
}
