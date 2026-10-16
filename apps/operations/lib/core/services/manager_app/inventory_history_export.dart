import 'dart:convert';
import '../../models/inventory_history_page.dart';

/// Re-read all bounded pages in one creation window. Never export a truncated
/// legacy response or a partially downloaded file as complete history.
Future<String> inventoryHistoryCsv(
  InventoryHistoryLoader load, {
  required Map<String, dynamic> filters,
  void Function()? requireCurrent,
}) async {
  final rows = <Map<String, dynamic>>[];
  final ids = <String>{}, cursors = <String>{};
  Map<String, dynamic>? window;
  String? cursor;
  do {
    requireCurrent?.call();
    final page = await load(cursor);
    requireCurrent?.call();
    if (!page.completeSource) throw StateError('Full history is unavailable');
    window ??= page.window;
    if (jsonEncode(window) != jsonEncode(page.window))
      throw StateError('History window changed');
    for (final row in page.items) {
      final id = row['id'];
      if (id is! String || !ids.add(id))
        throw StateError('Duplicate or missing history identity');
      rows.add(row);
    }
    cursor = page.nextCursor;
    if (cursor != null &&
        (cursor.isEmpty || !cursors.add(cursor) || page.items.isEmpty)) {
      throw StateError('History cursor did not advance');
    }
  } while (cursor != null);
  String csv(String text) => '"${text.replaceAll('"', '""')}"';
  // Untrusted labels are JSON inside a quoted cell starting with `{`; formula
  // prefixes cannot become spreadsheet instructions. IDs are prefixed too.
  return '\uFEFFid,filters,window,record_json\r\n${rows.map((r) => [csv('id:${r['id']}'), csv(jsonEncode(filters)), csv(jsonEncode(window)), csv(jsonEncode(r))].join(',')).join('\r\n')}\r\n';
}
