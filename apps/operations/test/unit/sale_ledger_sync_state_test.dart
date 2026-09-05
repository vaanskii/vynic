import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/sync/sale_ledger_sync_state.dart';

void main() {
  late Directory directory;

  Map<String, dynamic> retainedSale({String name = 'Original'}) => {
    'orderId': 42,
    'tableNumbers': ['1'],
    'floor': 'first',
    'items': [
      {
        'itemName': name,
        'quantity': 2,
        'unitPrice': 0.15,
        'total': 0.30,
        'menuItemId': 'menu-1',
        'variantId': 'variant-1',
        'comment': 'frozen note',
      },
    ],
    'totalAmount': 0.20,
    'grossSaleAmount': 0.30,
    'subtotalAmount': 0.30,
    'discountAmount': 0.0,
    'manualAdjustmentAmount': 0.0,
    'advanceApplied': 0.10,
    'collectedNow': 0.20,
    'paymentMethod': 'cash',
    'paymentBreakdown': {'cash': 0.20, 'advance': 0.10},
    'createdBy': 'waiter',
    'closedById': 'manager',
    'createdAt': '2026-09-04T10:00:00.000Z',
    'closedAt': '2026-09-04T10:30:00.000Z',
    'date': '2026-09-04',
    'isFiscal': true,
    'isCancelled': false,
    'restoredToOrder': false,
    'recordType': 'sale',
    'closureId': 'closure-42',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sale_ledger_state');
    Hive.init(directory.path);
    DatabaseCore.salesBox = await Hive.openBox('ledger_sales');
    DatabaseCore.settingsBox = await Hive.openBox('ledger_settings');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-09-05T00:00:00.000',
    );
  });

  tearDown(() async {
    await Hive.close();
    DatabaseCore.salesBox = null;
    DatabaseCore.settingsBox = null;
    await directory.delete(recursive: true);
  });

  test(
    'assigns backup-stable identity only to genuine retained Sales',
    () async {
      final saleKey = await DatabaseCore.salesBox!.add(retainedSale());
      await DatabaseCore.salesBox!.add({
        ...retainedSale(),
        'recordType': 'advance_receipt',
      });

      await SaleLedgerSyncState.ensureSaleIdentities();
      final assigned = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(saleKey) as Map,
      );
      final id = assigned['posSaleId'];
      expect(id, isNotEmpty);
      expect(assigned['ledgerRevision'], 1);
      expect((DatabaseCore.salesBox!.getAt(1) as Map)['posSaleId'], isNull);

      // Backup restore preserves map values while changing Hive keys.
      await DatabaseCore.salesBox!.clear();
      await DatabaseCore.salesBox!.add(Map<String, dynamic>.from(assigned));
      await SaleLedgerSyncState.ensureSaleIdentities();
      expect((DatabaseCore.salesBox!.getAt(0) as Map)['posSaleId'], id);
    },
  );

  test(
    'new local close freezes stable line identity before any network work',
    () async {
      final key = await SalesRepository.saveSaleRecord(
        orderId: 7,
        tableNumbers: const ['1'],
        floor: 'first',
        items: [
          OrderItem(
            itemKey: 'item-1',
            itemName: 'Frozen name',
            unitPrice: 10,
            quantity: 1,
            total: 10,
            comment: 'note',
            menuItemId: 'menu-1',
            variantId: 'variant-1',
          ),
        ],
        totalAmount: 10,
        paymentMethod: 'cash',
        paymentBreakdown: const {'cash': 10},
        createdBy: 'waiter',
        createdAt: DateTime.parse('2026-09-04T10:00:00Z'),
        closedAt: DateTime.parse('2026-09-04T10:30:00Z'),
        includeServiceFee: false,
        businessDate: '2026-09-04',
        closureId: 'closure-7',
        closedById: 'manager',
      );
      final stored = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(key) as Map,
      );
      expect(stored['posSaleId'], isNotEmpty);
      expect(stored['ledgerRevision'], 1);
      expect(stored['items'].single, containsPair('menuItemId', 'menu-1'));
      expect(stored['items'].single, containsPair('variantId', 'variant-1'));
      expect(stored['items'].single, containsPair('comment', 'note'));
    },
  );

  test(
    'emits exact strings, stable line identity and a bounded ACK backlog',
    () async {
      await DatabaseCore.salesBox!.add(retainedSale());
      await SaleLedgerSyncState.ensureSaleIdentities();
      final all = DatabaseCore.salesBox!.values.whereType<Map>().map(
        (row) => Map<String, dynamic>.from(row),
      );
      final batch = SaleLedgerSyncState.buildBatch(all);
      expect(batch, hasLength(1));
      expect(batch.single['gross'], '0.30');
      expect(batch.single['advanceApplied'], '0.10');
      expect(batch.single['amountDueNow'], '0.20');
      expect(batch.single['collectedNow'], '0.20');
      expect(batch.single['lines'][0], containsPair('menuItemId', 'menu-1'));
      expect(batch.single['lines'][0], containsPair('variantId', 'variant-1'));

      await SaleLedgerSyncState.acknowledgeResponse(
        '{"saleLedgerAck":[{"posSaleId":"${batch.single['posSaleId']}","revision":1}]}',
      );
      expect(SaleLedgerSyncState.buildBatch(all), isEmpty);
    },
  );

  test(
    'old backend response leaves the retained Sale safely pending',
    () async {
      await DatabaseCore.salesBox!.add(retainedSale());
      await SaleLedgerSyncState.ensureSaleIdentities();
      final all = DatabaseCore.salesBox!.values
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      expect(
        await SaleLedgerSyncState.acknowledgeResponse('{"success":true}'),
        isFalse,
      );
      expect(SaleLedgerSyncState.buildBatch(all), hasLength(1));
    },
  );

  test(
    'lifecycle mutation increments revision and re-enters the backlog',
    () async {
      final key = await DatabaseCore.salesBox!.add(retainedSale());
      await SaleLedgerSyncState.ensureSaleIdentities();
      final original = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(key) as Map,
      );
      await SaleLedgerSyncState.acknowledgeResponse(
        '{"saleLedgerAck":[{"posSaleId":"${original['posSaleId']}","revision":1}]}',
      );
      final changed = Map<String, dynamic>.from(original)
        ..['restoredToOrder'] = true;
      SaleLedgerSyncState.markLifecycleChanged(
        changed,
        DateTime.parse('2026-09-04T11:00:00Z'),
      );
      await DatabaseCore.salesBox!.put(key, changed);
      final batch = SaleLedgerSyncState.buildBatch([changed]);
      expect(batch.single['revision'], 2);
      expect(batch.single['restoredToOrder'], isTrue);
    },
  );

  test(
    'closed day is complete only after every Sale revision is ACKed',
    () async {
      await DatabaseCore.salesBox!.add(retainedSale());
      await SaleLedgerSyncState.ensureSaleIdentities();
      final all = DatabaseCore.salesBox!.values
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      var declaration = SaleLedgerSyncState.buildDayDeclarations(
        allRecords: all,
        currentBusinessDate: '2026-09-05',
      ).single;
      expect(declaration['uploadComplete'], isFalse);

      final id = all.single['posSaleId'];
      await SaleLedgerSyncState.acknowledgeResponse(
        '{"saleLedgerAck":[{"posSaleId":"$id","revision":1}]}',
      );
      declaration = SaleLedgerSyncState.buildDayDeclarations(
        allRecords: all,
        currentBusinessDate: '2026-09-05',
      ).single;
      expect(declaration['uploadComplete'], isTrue);
      expect(declaration['expectedSaleCount'], 1);
      expect(declaration['expectedRevenue'], '0.30');
    },
  );
}
