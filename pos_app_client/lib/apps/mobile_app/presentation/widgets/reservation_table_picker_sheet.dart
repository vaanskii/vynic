import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

/// Multi-select table picker for reservations (same floor, date-aware).
class ReservationTablePickerSheet {
  ReservationTablePickerSheet._();

  /// Returns encoded reservation table codes, or null if cancelled.
  static Future<List<int>?> show({
    required BuildContext context,
    required DateTime reservationDate,
    required String reservationTime,
    String? excludeReservationId,
  }) async {
    List<TableModel> tables;
    List<Map<String, dynamic>> reservations;
    try {
      final dateKey = ReservationTableAvailability.dateKey(reservationDate);
      final results = await Future.wait([
        MobileApiService.getTables(),
        MobileApiService.getReservations(date: dateKey),
      ]);
      tables = ReservationTableAvailability.sortTables(
        results[0] as List<TableModel>,
      );
      reservations = results[1] as List<Map<String, dynamic>>;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('მაგიდების ჩატვირთვა ვერ მოხერხდა'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return null;
    }

    final unavailable =
        ReservationTableAvailability.unavailableTableCodesFromApiReservations(
          reservations: reservations,
          excludeReservationId: excludeReservationId,
        );

    final selectableCount = tables
        .where(
          (table) => ReservationTableAvailability.isTableModelAvailable(
            table: table,
            unavailableCodes: unavailable,
          ),
        )
        .length;

    if (!context.mounted) return null;
    if (selectableCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('თავისუფალი მაგიდა არ არის არჩეულ თარიღზე'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return null;
    }

    String? selectedFloor;
    final selectedTables = <String>{};

    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobileGlassTheme.data.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'აირჩიე მაგიდა',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: MobileGlassTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'წითელი მაგიდები უკვე დაჯავშნულია ამ თარიღზე',
                      style: TextStyle(
                        color: MobileGlassTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tables.map((t) {
                        final code =
                            ReservationTableAvailability.encodeTableCode(
                              floor: t.floor,
                              tableNumber: t.tableNumber,
                            );
                        final isTaken = unavailable.contains(code);
                        final isSel =
                            !isTaken &&
                            selectedTables.contains(t.tableNumber) &&
                            selectedFloor == t.floor;
                        final disabled =
                            isTaken ||
                            (selectedFloor != null && selectedFloor != t.floor);
                        return GestureDetector(
                          onTap: disabled
                              ? null
                              : () {
                                  setSheetState(() {
                                    if (isSel) {
                                      selectedTables.remove(t.tableNumber);
                                      if (selectedTables.isEmpty) {
                                        selectedFloor = null;
                                      }
                                    } else {
                                      selectedFloor = t.floor;
                                      selectedTables.add(t.tableNumber);
                                    }
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isTaken
                                  ? Colors.red.withValues(alpha: 0.15)
                                  : isSel
                                  ? MobileGlassTheme.primary
                                  : MobileGlassTheme.surface(
                                      disabled ? 0.02 : 0.05,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isTaken
                                    ? Colors.red
                                    : isSel
                                    ? MobileGlassTheme.primary
                                    : MobileGlassTheme.data.borderSubtle,
                              ),
                            ),
                            child: Text(
                              ReservationTableAvailability.displayLabel(
                                floor: t.floor,
                                tableNumber: t.tableNumber,
                              ),
                              style: TextStyle(
                                color: isTaken
                                    ? Colors.red
                                    : isSel
                                    ? Colors.white
                                    : MobileGlassTheme.textPrimary.withValues(
                                        alpha: disabled ? 0.35 : 0.85,
                                      ),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            selectedTables.isEmpty || selectedFloor == null
                            ? null
                            : () {
                                final codes =
                                    ReservationTableAvailability.encodeFloorSelection(
                                      floor: selectedFloor!,
                                      tableNumbers: selectedTables.toList(),
                                    );
                                Navigator.of(sheetContext).pop(codes);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MobileGlassTheme.primary,
                          disabledBackgroundColor: MobileGlassTheme.primary
                              .withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'დადასტურება',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
