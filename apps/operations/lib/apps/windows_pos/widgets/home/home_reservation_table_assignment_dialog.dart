import 'package:flutter/material.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

class HomeReservationTableAssignmentDialog {
  const HomeReservationTableAssignmentDialog._();

  static Future<List<TableRef>?> show({
    required BuildContext context,
    required DateTime reservationDate,
    required String reservationTime,
    required Color primaryColor,
    required Color secondaryColor,
    required Color textPrimary,
    String? excludeReservationId,
    int? excludeOrderId,
    List<TableRef> initialSelection = const [],
  }) async {
    final reservations = DatabaseService.getTableBlockingReservationsForDate(
      reservationDate,
    );
    final unavailable =
        ReservationTableAvailability.unavailableTableRefsFromReservations(
          reservations: reservations,
          excludeReservationId: excludeReservationId,
        );

    // For same-day assignment the reservation-record check above is not
    // enough: tables can be locked live by walk-in orders or activated
    // reservations (TableModel.isReserved / activeOrderId), which
    // isRealTableBooking deliberately excludes. Clear stale locks first,
    // then block whatever is still genuinely held.
    final isToday = ReservationTableAvailability.isSameCalendarDate(
      reservationDate,
      DatabaseService.getCurrentDate(),
    );
    if (isToday) {
      await DatabaseService.releaseStaleReservedTables();
      unavailable.addAll(
        ReservationTableAvailability.unavailableTableRefsFromLiveTables(
          tables: DatabaseService.getAllTables(),
          excludeReservationId: excludeReservationId,
          excludeOrderId: excludeOrderId,
        ),
      );
    }

    final allTables = ReservationTableAvailability.sortTables(
      DatabaseService.getAllTables(),
    );

    final selectableCount = allTables
        .where(
          (table) => !unavailable.contains(
            ReservationTableAvailability.refOfTableModel(table),
          ),
        )
        .length;

    if (selectableCount == 0) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text('მაგიდები', style: TextStyle(color: textPrimary)),
            content: const Text('თავისუფალი მაგიდა არ არის არჩეულ თარიღზე.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return null;
    }

    final layout = DatabaseService.getRestaurantTableLayout();
    String floorNameOf(String floor) =>
        layout.zoneForLegacyFloor(floor)?.name ??
        ReservationTableAvailability.floorLabel(floor);

    String? selectedFloor;
    final selectedRefs = <TableRef>{...initialSelection};

    if (selectedRefs.isNotEmpty) {
      selectedFloor = selectedRefs.first.floor;
    }

    return showDialog<List<TableRef>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text('სუფრის არჩევა', style: TextStyle(color: textPrimary)),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'წითელი მაგიდები უკვე დაჯავშნულია ამ თარიღზე. '
                    'ერთ სართულზე შეგიძლიათ რამდენიმე თავისუფალი მაგიდის არჩევა.',
                    style: TextStyle(
                      color: textPrimary.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: allTables.map((table) {
                      return _tableChip(
                        table: table,
                        selectedFloor: selectedFloor,
                        selectedRefs: selectedRefs,
                        unavailable: unavailable,
                        floorNameOf: floorNameOf,
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor,
                        textPrimary: textPrimary,
                        onTap: () {
                          setDialogState(() {
                            final ref =
                                ReservationTableAvailability.refOfTableModel(
                                  table,
                                );
                            if (unavailable.contains(ref)) {
                              return;
                            }
                            final isSelected = selectedRefs.contains(ref);
                            if (isSelected) {
                              selectedRefs.remove(ref);
                              if (selectedRefs.isEmpty) {
                                selectedFloor = null;
                              }
                            } else {
                              if (selectedFloor != null &&
                                  selectedFloor != table.floor) {
                                return;
                              }
                              selectedFloor = table.floor;
                              selectedRefs.add(ref);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('გაუქმება'),
              ),
              ElevatedButton(
                onPressed: selectedRefs.isEmpty
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        _sortedRefs(selectedRefs),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('დადასტურება'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<List<TableRef>?> showForReservation({
    required BuildContext context,
    required Reservation reservation,
    required Color primaryColor,
    required Color secondaryColor,
    required Color textPrimary,
  }) {
    return show(
      context: context,
      reservationDate: reservation.reservationDate,
      reservationTime: reservation.reservationTime,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      textPrimary: textPrimary,
      excludeReservationId: reservation.id,
      excludeOrderId: reservation.linkedOrderId,
      initialSelection: ReservationTableAvailability.tableRefsOf(reservation),
    );
  }

  static List<TableRef> _sortedRefs(Set<TableRef> refs) {
    return refs.toList()..sort((a, b) {
      final floorCmp = a.floor.compareTo(b.floor);
      if (floorCmp != 0) return floorCmp;
      return (int.tryParse(a.tableNumber) ?? 0).compareTo(
        int.tryParse(b.tableNumber) ?? 0,
      );
    });
  }

  static Widget _tableChip({
    required TableModel table,
    required String? selectedFloor,
    required Set<TableRef> selectedRefs,
    required Set<TableRef> unavailable,
    required String Function(String floor) floorNameOf,
    required Color primaryColor,
    required Color secondaryColor,
    required Color textPrimary,
    required VoidCallback onTap,
  }) {
    final ref = ReservationTableAvailability.refOfTableModel(table);
    final isUnavailable = unavailable.contains(ref);
    final isSelected = selectedRefs.contains(ref);
    final disabled =
        !isUnavailable && selectedFloor != null && selectedFloor != table.floor;

    return InkWell(
      onTap: isUnavailable || disabled ? null : onTap,
      child: Container(
        width: 130,
        height: 84,
        decoration: BoxDecoration(
          color: isUnavailable
              ? Colors.red.withValues(alpha: 0.15)
              : isSelected
              ? secondaryColor
              : const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnavailable
                ? Colors.red
                : isSelected
                ? secondaryColor
                : primaryColor.withValues(alpha: disabled ? 0.08 : 0.2),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.table_restaurant,
              color: isUnavailable
                  ? Colors.red
                  : isSelected
                  ? Colors.white
                  : primaryColor.withValues(alpha: disabled ? 0.35 : 1),
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              ReservationTableAvailability.displayLabelForRef(
                ref,
                floorNameOf: floorNameOf,
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isUnavailable
                    ? Colors.red
                    : isSelected
                    ? Colors.white
                    : textPrimary.withValues(alpha: disabled ? 0.35 : 1),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
