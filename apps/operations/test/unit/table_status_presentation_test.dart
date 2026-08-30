// Tests for [TableStatusPresentation] — the UI Phase 3 mapping from
// [TableOperationalStatus] to what a table tile shows (icon/label/tone).
// This is the single place every render mode in table_selection_widget.dart
// (SVG map, floor plan, button grid) derives its status presentation from —
// locking the mapping here prevents the three modes from drifting apart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/home/table_status_presentation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';
import 'package:vynic/core/ui/vynic_status_tokens.dart';

void main() {
  group('TableStatusPresentation.forStatus', () {
    test('free maps to the neutral Vynic state', () {
      final presentation = TableStatusPresentation.forStatus(
        TableOperationalStatus.free,
      );
      expect(presentation.vynicState, VynicOperationalState.free);
      expect(presentation.isFree, isTrue);
      expect(presentation.isBusy, isFalse);
      expect(
        VynicStatusTokens.toneForState(presentation.vynicState),
        VynicStatusTone.neutral,
      );
    });

    test('occupied maps to the info Vynic state, distinct from reserved', () {
      final presentation = TableStatusPresentation.forStatus(
        TableOperationalStatus.occupied,
      );
      expect(presentation.vynicState, VynicOperationalState.occupied);
      expect(presentation.isBusy, isTrue);
      expect(
        VynicStatusTokens.toneForState(presentation.vynicState),
        VynicStatusTone.info,
      );
    });

    test('reserved maps to the warning Vynic state', () {
      final presentation = TableStatusPresentation.forStatus(
        TableOperationalStatus.reserved,
      );
      expect(presentation.vynicState, VynicOperationalState.reserved);
      expect(presentation.isBusy, isTrue);
      expect(
        VynicStatusTokens.toneForState(presentation.vynicState),
        VynicStatusTone.warning,
      );
    });

    test('occupied and reserved never resolve to the same icon or label', () {
      final occupied = TableStatusPresentation.forStatus(
        TableOperationalStatus.occupied,
      );
      final reserved = TableStatusPresentation.forStatus(
        TableOperationalStatus.reserved,
      );
      // Regression guard for the bug this phase fixed: both used to render
      // identically ("დაკავებულია" + Icons.lock) because the tile code only
      // checked the raw `isReserved` boolean, which is true for both.
      expect(occupied.label, isNot(reserved.label));
      expect(occupied.icon, isNot(reserved.icon));
    });
  });

  group('TableStatusPresentation.of', () {
    test('a table with an active order presents as occupied', () {
      final table = TableModel(tableNumber: '1', floor: 'first')
        ..reserve('waiter1', 42);
      final presentation = TableStatusPresentation.of(table);
      expect(presentation.status, TableOperationalStatus.occupied);
    });

    test('a table reserved without an order presents as reserved', () {
      final table = TableModel(tableNumber: '1', floor: 'first')
        ..reserveForReservation('waiter1', 'res-1');
      final presentation = TableStatusPresentation.of(table);
      expect(presentation.status, TableOperationalStatus.reserved);
    });

    test('a free table presents as free', () {
      final table = TableModel(tableNumber: '1', floor: 'first');
      expect(
        TableStatusPresentation.of(table).status,
        TableOperationalStatus.free,
      );
    });

    test('a missing (null) table presents as free', () {
      expect(
        TableStatusPresentation.of(null).status,
        TableOperationalStatus.free,
      );
    });

    test('icon is a valid IconData for every status', () {
      for (final status in TableOperationalStatus.values) {
        expect(TableStatusPresentation.forStatus(status).icon, isA<IconData>());
      }
    });
  });
}
