// Tests for [TableModel.operationalStatus] — the derived disambiguation of
// the `isReserved` boolean that today conflates "booked for a reservation"
// and "occupied with a live order". Pure derivation, no storage involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';

void main() {
  group('TableModel.operationalStatus', () {
    test('free: not reserved, no active order', () {
      final table = TableModel(tableNumber: '1', floor: 'first');
      expect(table.operationalStatus, TableOperationalStatus.free);
    });

    test('reserved: isReserved true, no active order yet', () {
      final table = TableModel(tableNumber: '1', floor: 'first')
        ..reserveForReservation('waiter1', 'res-1');
      expect(table.operationalStatus, TableOperationalStatus.reserved);
    });

    test('occupied: has an active order, regardless of isReserved', () {
      final table = TableModel(tableNumber: '1', floor: 'first')
        ..reserve('waiter1', 42);
      expect(table.operationalStatus, TableOperationalStatus.occupied);
    });

    test('occupied takes priority over reserved when both are set', () {
      final table = TableModel(
        tableNumber: '1',
        floor: 'first',
        isReserved: true,
        activeOrderId: 42,
      );
      expect(table.operationalStatus, TableOperationalStatus.occupied);
    });

    test('free() resets to free', () {
      final table = TableModel(tableNumber: '1', floor: 'first')
        ..reserve('waiter1', 42)
        ..free();
      expect(table.operationalStatus, TableOperationalStatus.free);
    });
  });
}
