import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/inventory_history_page.dart';
import 'package:vynic/core/services/manager_app/inventory_history_export.dart';

const window = {
  'recordsCreatedBefore': '2026-10-08T10:00:00.000Z',
  'state': 'CURRENT_AT_EACH_REQUEST',
};
InventoryHistoryPage page(List<Map<String, dynamic>> rows, [String? cursor]) =>
    InventoryHistoryPage(items: rows, nextCursor: cursor, window: window);
void main() {
  test(
    'exports all 205 records across bounded pages including quoted JSON and frozen value',
    () async {
      final requested = <String?>[];
      final csv = await inventoryHistoryCsv((cursor) async {
        requested.add(cursor);
        final start = cursor == null ? 0 : int.parse(cursor);
        final end = (start + 50).clamp(0, 205);
        return page([
          for (var i = start; i < end; i++)
            {
              'id': '$i',
              'name': '=HYPERLINK("bad")\nკერძი',
              'inventoryValueDelta': '-60.000000000000',
              'valueOrigin': 'CLOUD_ACCEPTANCE',
            },
        ], end < 205 ? '$end' : null);
      }, filters: {'from': '2026-09-05', 'to': '2026-09-05'});
      expect(requested, [null, '50', '100', '150', '200']);
      expect(RegExp('"id:').allMatches(csv).length, 205);
      expect(csv, contains('"id:204"'));
      expect(csv, contains('CLOUD_ACCEPTANCE'));
      expect(csv, contains('recordsCreatedBefore'));
      expect(csv, contains('=HYPERLINK'));
      expect(csv.split('\r\n').length, 207);
    },
  );
  test(
    'interrupted export fails without returning partial output and retry starts at first page',
    () async {
      var fail = true;
      final calls = <String?>[];
      Future<InventoryHistoryPage> load(String? cursor) async {
        calls.add(cursor);
        if (cursor != null && fail) throw StateError('offline');
        return cursor == null
            ? page([
                {'id': '1'},
              ], 'next')
            : page([
                {'id': '2'},
              ]);
      }

      await expectLater(
        inventoryHistoryCsv(load, filters: {}),
        throwsStateError,
      );
      fail = false;
      final csv = await inventoryHistoryCsv(load, filters: {});
      expect(calls, [null, 'next', null, 'next']);
      expect(RegExp('"id:').allMatches(csv).length, 2);
    },
  );
  test(
    'rejects duplicate identities, repeated cursors, changed windows and legacy truncation',
    () async {
      for (final second in [
        page([
          {'id': '1'},
        ]),
        page([
          {'id': '2'},
        ], 'next'),
        const InventoryHistoryPage(
          items: [
            {'id': '2'},
          ],
          window: {'other': true},
        ),
        const InventoryHistoryPage(items: [], completeSource: false),
      ]) {
        await expectLater(
          inventoryHistoryCsv(
            (c) async => c == null
                ? page([
                    {'id': '1'},
                  ], 'next')
                : second,
            filters: {},
          ),
          throwsStateError,
        );
      }
    },
  );
  test(
    'filter/session cancellation prevents completed bytes escaping after async page',
    () async {
      final response = Completer<InventoryHistoryPage>();
      var current = true;
      final export = inventoryHistoryCsv(
        (_) => response.future,
        filters: {},
        requireCurrent: () {
          if (!current) throw StateError('changed');
        },
      );
      current = false;
      response.complete(
        page([
          {'id': '1'},
        ]),
      );
      await expectLater(export, throwsStateError);
    },
  );
}
