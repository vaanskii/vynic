import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/services/sync/sale_ledger_sync_state.dart';

/// Opt-in characterization of a retained POS store. Only a temporary copy is
/// opened with Hive; neither live records nor local ACKs are changed.
void main() {
  final source = Platform.environment['POS_RETAINED_SALES_HIVE'];
  final output = Platform.environment['POS_RETAINED_SALES_WIRE_OUTPUT'];
  test(
    'serialize every retained Sale for backend compatibility validation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'retained_sale_test',
      );
      try {
        await File(source!).copy('${directory.path}/sales.hive');
        Hive.init(directory.path);
        final box = await Hive.openBox('sales');
        final rows = box.values
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .where((r) => (r['recordType'] ?? 'sale') == 'sale')
            .toList();
        final payload = <Map<String, dynamic>>[];
        for (
          var offset = 0;
          offset < rows.length;
          offset += SaleLedgerSyncState.batchSize
        ) {
          payload.addAll(
            SaleLedgerSyncState.buildBatch(
              rows.skip(offset).take(SaleLedgerSyncState.batchSize),
            ),
          );
        }
        // Do not silently omit older rows whose stable identities were never set.
        expect(payload, hasLength(rows.length));
        for (final row in payload.where((r) => r['isFiscal'] == false)) {
          expect(row['collectedNow'], '0.00', reason: '${row['posSaleId']}');
          expect(row['payments'], isEmpty, reason: '${row['posSaleId']}');
        }
        await File(output!).writeAsString(jsonEncode(payload));
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
    skip: source == null || output == null
        ? 'Set POS_RETAINED_SALES_HIVE and POS_RETAINED_SALES_WIRE_OUTPUT to inspect a local copy.'
        : false,
  );
}
