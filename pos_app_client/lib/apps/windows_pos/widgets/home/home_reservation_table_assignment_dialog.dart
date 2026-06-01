import 'package:flutter/material.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/services/database_service.dart';

class HomeReservationTableAssignmentDialog {
  const HomeReservationTableAssignmentDialog._();

  static Future<List<int>?> show({
    required BuildContext context,
    required Reservation reservation,
    required Color primaryColor,
    required Color secondaryColor,
    required Color textPrimary,
  }) async {
    final selectedDate = reservation.reservationDate;
    final resTime = reservation.reservationTime;
    final parts = resTime.split(':');
    final resMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);

    final reservations = DatabaseService.getReservationsForDate(selectedDate);
    final unavailableTables = <int>{};
    for (final existing in reservations) {
      if (existing.id == reservation.id) {
        continue;
      }
      if (existing.status != 'cancelled' && existing.status != 'completed') {
        final existingParts = existing.reservationTime.split(':');
        final existingMinutes =
            int.parse(existingParts[0]) * 60 + int.parse(existingParts[1]);
        if ((resMinutes < existingMinutes + 120) &&
            (existingMinutes < resMinutes + 120)) {
          unavailableTables.addAll(existing.tableNumbers);
        }
      }
    }

    final allTables = <String, bool>{
      'Table 1': false,
      'Table 2': false,
      'Table 3': false,
      'Table 4': false,
      'Table 5': false,
      'Table 6': false,
      'Table 7': false,
      'Table 8': false,
      'Table 9': false,
      'Table 10': false,
    };

    return showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text('სუფრის არჩევა', style: TextStyle(color: textPrimary)),
            content: SizedBox(
              width: 520,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: allTables.keys.map((tableName) {
                  final tableNumber = int.parse(
                    tableName.replaceAll('Table ', ''),
                  );
                  final isUnavailable = unavailableTables.contains(tableNumber);
                  final isSelected = allTables[tableName] ?? false;

                  return InkWell(
                    onTap: isUnavailable
                        ? null
                        : () {
                            setDialogState(() {
                              allTables[tableName] = !isSelected;
                            });
                          },
                    child: Container(
                      width: 120,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isUnavailable
                            ? Colors.red.withValues(alpha: 0.2)
                            : isSelected
                            ? secondaryColor
                            : const Color(0xFFF8FAFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isUnavailable
                              ? Colors.red
                              : isSelected
                              ? secondaryColor
                              : primaryColor.withValues(alpha: 0.2),
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
                                : primaryColor,
                            size: 28,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'სუფრა ${tableName.replaceAll('Table ', '')}',
                            style: TextStyle(
                              color: isUnavailable
                                  ? Colors.red
                                  : isSelected
                                  ? Colors.white
                                  : textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('გაუქმება'),
              ),
              ElevatedButton(
                onPressed: () {
                  final selected = allTables.entries
                      .where((entry) => entry.value)
                      .map(
                        (entry) =>
                            int.parse(entry.key.replaceAll('Table ', '')),
                      )
                      .toList();
                  Navigator.pop(dialogContext, selected);
                },
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
}
