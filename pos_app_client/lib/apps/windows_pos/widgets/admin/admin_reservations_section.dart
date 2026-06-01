import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation_context.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservations_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/reservations_management_section.dart';

class AdminReservationsSection extends StatefulWidget {
  final User user;

  const AdminReservationsSection({super.key, required this.user});

  @override
  State<AdminReservationsSection> createState() =>
      _AdminReservationsSectionState();
}

class _AdminReservationsSectionState extends State<AdminReservationsSection> {
  String _reservationStatusFilter = 'confirmed';
  DateTime? _reservationDateFilter;

  @override
  void initState() {
    super.initState();
    _reservationDateFilter = null;
  }

  @override
  Widget build(BuildContext context) {
    return _buildReservationsSection();
  }

  String _normalizeStatus(String status) {
    return status
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  Widget _buildReservationsSection() {
    final currentDate = DatabaseService.getCurrentDate();
    final normalizedToday = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );

    final filteredReservations =
        DatabaseService.getAllReservations().where((reservation) {
          if (reservation.isTakeAway) {
            return false;
          }
          if (reservation.notes != null &&
              reservation.notes!.startsWith('Order #')) {
            return false;
          }

          final normalizedStatus = _normalizeStatus(reservation.status);
          final isConfirmed = normalizedStatus.startsWith('confirmed');
          final isCancelled =
              normalizedStatus.startsWith('cancelled') ||
              normalizedStatus.startsWith('canceled');

          if (!isConfirmed && !isCancelled) {
            return false;
          }

          final reservationDateOnly = DateTime(
            reservation.reservationDate.year,
            reservation.reservationDate.month,
            reservation.reservationDate.day,
          );

          return !reservationDateOnly.isBefore(normalizedToday);
        }).toList()..sort((a, b) {
          final dateComparison = a.reservationDate.compareTo(b.reservationDate);
          if (dateComparison != 0) {
            return dateComparison;
          }
          return a.reservationTime.compareTo(b.reservationTime);
        });

    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: double.infinity,
        child: ReservationsManagementSection(
          reservations: filteredReservations,
          normalizedToday: normalizedToday,
          filterDate: _reservationDateFilter,
          statusFilter: _reservationStatusFilter,
          isAdminUser: widget.user.isAdmin,
          showCancelledTab: true,
          onFilterDateChanged: (value) {
            setState(() => _reservationDateFilter = value);
          },
          onStatusFilterChanged: (value) {
            setState(() => _reservationStatusFilter = value);
          },
          onCreateReservation: _showReservationDialog,
          onCancelReservation: (reservation) =>
              _updateReservationStatus(reservation, 'cancelled'),
          onDeleteReservation: _deleteReservation,
        ),
      ),
    );
  }

  Future<void> _showReservationDialog() async {
    String? initialName;
    String? initialPhone;
    String? initialNotes;
    DateTime? initialDate;
    TimeOfDay? initialTime;
    int? initialGuests;

    while (mounted) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return Material(
            color: Colors.transparent,
            child: ReservationCreationSheet(
              initialName: initialName,
              initialPhone: initialPhone,
              initialNotes: initialNotes,
              initialDate: initialDate,
              initialTime: initialTime,
              initialGuests: initialGuests,
            ),
          );
        },
      );

      if (result == null) {
        return;
      }

      final selectedDate = result['date'] as DateTime?;
      final selectedTime = result['time'] as TimeOfDay?;
      if (selectedDate == null || selectedTime == null) {
        return;
      }

      final customerName = (result['customerName'] as String? ?? '').trim();
      final customerPhone = (result['customerPhone'] as String? ?? '').trim();
      final notesRaw = (result['notes'] as String?)?.trim();
      final guestCount =
          (result['numberOfGuests'] as int?) ?? (result['guests'] as int?) ?? 2;

      initialName = customerName;
      initialPhone = customerPhone;
      initialNotes = notesRaw;
      initialDate = selectedDate;
      initialTime = selectedTime;
      initialGuests = guestCount;

      final timeString =
          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

      if (!mounted) {
        return;
      }

      final selectedItems = await Navigator.push<List<OrderItem>>(
        context,
        MaterialPageRoute(
          builder: (context) => MenuScreen(
            user: widget.user,
            selectedTables: const [],
            isPreOrderMode: true,
            reservationContext: ReservationContext(
              customerName: customerName,
              customerPhone: customerPhone,
              reservationDate: selectedDate,
              reservationTime: timeString,
              tableNumbers: const [],
              tableLabels: const [],
              numberOfGuests: guestCount,
              notes: (notesRaw == null || notesRaw.isEmpty) ? null : notesRaw,
            ),
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      if (selectedItems == null) {
        continue;
      }

      final reservationId = await DatabaseService.createReservation(
        customerName: customerName,
        customerPhone: customerPhone,
        tableNumbers: const [],
        reservationDate: selectedDate,
        reservationTime: timeString,
        numberOfGuests: guestCount,
        notes: (notesRaw == null || notesRaw.isEmpty) ? null : notesRaw,
        createdBy: widget.user.username,
        status: 'confirmed',
      );

      await DatabaseService.updateReservationPreOrderItems(
        reservationId,
        selectedItems,
      );

      final createdReservation = Reservation(
        id: reservationId,
        customerName: customerName,
        customerPhone: customerPhone,
        tableNumbers: const [],
        reservationDate: selectedDate,
        reservationTime: timeString,
        numberOfGuests: guestCount,
        notes: (notesRaw == null || notesRaw.isEmpty) ? null : notesRaw,
        createdAt: DatabaseService.getCurrentDateTime(),
        createdBy: widget.user.username,
        status: 'confirmed',
        preOrderItems: selectedItems,
      );

      _sendReservationKitchenCheck(createdReservation);

      if (!mounted) {
        return;
      }

      unawaited(showSuccessToast(context, 'Reservation created successfully'));
      setState(() {});
      return;
    }
  }

  void _sendReservationKitchenCheck(Reservation reservation) {
    final kitchenItems = HomeReservationsHelper.buildKitchenCheckLines(
      reservation,
    );
    if (kitchenItems.isEmpty) {
      return;
    }

    final orderLabel = HomeReservationsHelper.buildKitchenOrderLabel(
      reservation,
    );
    final createdAt = HomeReservationsHelper.buildKitchenTime(reservation);

    PrinterService.printKitchenCheckInBackground(
      items: kitchenItems,
      tableNumber: reservation.tableNumbers.isNotEmpty
          ? reservation.tableNumbers.join(', ')
          : null,
      orderNumber: orderLabel,
      waiterName: widget.user.username,
      createdAt: createdAt,
      onComplete: (success) {
        if (!mounted) {
          return;
        }
        if (success) {
          unawaited(showSuccessToast(context, 'ჩეკი გაიგზავნა სამზარეულოში'));
        } else {
          unawaited(showErrorToast(context, 'პრინტერი მიუწვდომელია'));
        }
      },
    );
  }

  Future<void> _updateReservationStatus(
    Reservation reservation,
    String newStatus,
  ) async {
    final currentDate = DatabaseService.getCurrentDate();
    final currentDateString = currentDate.toIso8601String().split('T')[0];
    final resDateString = reservation.reservationDate.toIso8601String().split(
      'T',
    )[0];
    final bool isTodayReservation = resDateString == currentDateString;

    if (newStatus == 'confirmed' &&
        isTodayReservation &&
        !widget.user.isAdmin) {
      if (mounted) {
        unawaited(
          showErrorToast(
            context,
            'Only administrators can seat today\'s reservations.',
          ),
        );
      }
      return;
    }

    final previousStatus = reservation.status;
    await DatabaseService.updateReservationStatus(reservation.id, newStatus);

    if (newStatus == 'cancelled') {
      await DatabaseService.logAdminAction(
        actionType: 'reservation_cancelled',
        performedBy: widget.user.username,
        comment: 'Reservation cancelled via Admin panel',
        details: {
          'reservationId': reservation.id,
          'customerName': reservation.customerName,
          'reservationDate': reservation.reservationDate.toIso8601String(),
          'reservationTime': reservation.reservationTime,
          'tableNumbers': reservation.tableNumbers,
          'previousStatus': previousStatus,
          'newStatus': newStatus,
          'isTakeAway': reservation.isTakeAway,
          'linkedOrderId': reservation.linkedOrderId,
          'notes': reservation.notes,
          'performedByRole': widget.user.role,
        },
      );
    }

    if (mounted) {
      unawaited(showSuccessToast(context, 'Reservation $newStatus'));
    }

    setState(() {});
  }

  Future<void> _deleteReservation(Reservation reservation) async {
    // Confirmation is already handled by the reservations management section
    // before this callback fires, so we delete directly (no second dialog).
    await DatabaseService.deleteReservation(reservation.id);
    if (!mounted) return;
    setState(() {});
    unawaited(showSuccessToast(context, 'Reservation deleted'));
  }
}
